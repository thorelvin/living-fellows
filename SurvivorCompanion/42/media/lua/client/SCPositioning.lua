-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Positioning = SC.Positioning or {}
local Positioning = SC.Positioning

-- Local X is right/left of the leader; local Y is distance behind the
-- leader's travel direction. Stable identity ordering prevents companions
-- swapping sides from one decision pulse to the next.
local formationOffsets = {
    { -1, 1 }, { 1, 1 }, { -2, 0 }, { 2, 0 },
    { -2, 2 }, { 2, 2 }, { -1, 3 }, { 1, 3 },
}

-- The player remains the formation leader. These roles order the followers
-- behind them: a close fighter takes the first portal slot, firearm users stay
-- in the protected middle, and the rear guard crosses last. The assignment is
-- derived from doctrine, personality and the equipped weapon on the bounded
-- fireteam-roster pulse rather than by adding work to every frame.
local cqbRoleOrder = {
    point = 1,
    assault = 2,
    ranged_support = 3,
    rear_guard = 4,
}

local states = setmetatable({}, { __mode = "k" })
local leaderStates = setmetatable({}, { __mode = "k" })
local targetReservations = {}
local nextReservationSweepAt = 0
local emptyFireteam = {}
local emptyFireteamSlots = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function stateFor(actor)
    local state = states[actor]
    if state == nil then
        state = {}
        states[actor] = state
    end
    return state
end

local function normalized(x, y)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return nil, nil end
    local length = math.sqrt(x * x + y * y)
    if length < 0.001 then return nil, nil end
    return x / length, y / length
end

local function leaderStateFor(leader)
    local state = leaderStates[leader]
    if state == nil then
        state = { trail = {}, revision = 0 }
        leaderStates[leader] = state
    end
    return state
end

local function commandState(other)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, value = pcall(SC.Commands.peek, other)
        if ok and type(value) == "table" then return value end
    end
    return nil
end

local function cqbMetrics(entry)
    local utility = U()
    local commands = type(entry.commands) == "table" and entry.commands or {}
    local profile = type(commands.personalityProfile) == "table"
        and commands.personalityProfile or {}
    local background = type(commands.background) == "table" and commands.background
        or type(profile.background) == "table" and profile.background or {}
    local primary = select(1, utility.call(entry.actor, "getPrimaryHandItem"))
    local primaryRanged = primary ~= nil
        and select(1, utility.call(primary, "isRanged")) == true
    local armed = primary ~= nil and (utility.instanceOf(primary, "HandWeapon")
        or utility.instanceOf(primary, "zombie.inventory.types.HandWeapon")
        or utility.hasMethod(primary, "getMaxDamage"))
    local ranged = primaryRanged or commands.combatDoctrine == "ranged_support"
        or commands.weaponPriority == "firearm"
    local courage = tonumber(profile.courage) or 50
    local caution = tonumber(profile.caution) or 50
    local practicality = tonumber(profile.practicality) or 50
    local aptitude = string.lower(tostring(background.aptitude or profile.aptitude or ""))
    entry.rangedCapable = ranged == true
    entry.pointScore = courage * 0.65 + practicality * 0.15
        + (ranged and -45 or 35) + (armed and 12 or 0)
        + (commands.combatDoctrine == "close_defense" and 10 or 0)
        + (commands.combatDoctrine == "weapons_free" and 6 or 0)
    entry.rearScore = caution * 0.7 + practicality * 0.15
        + (aptitude == "keen_hearing" and 28 or 0)
        + (ranged and 5 or 0)
    return entry
end

local function betterRoleCandidate(candidate, best, field)
    if best == nil then return true end
    local candidateScore = tonumber(candidate[field]) or 0
    local bestScore = tonumber(best[field]) or 0
    if candidateScore ~= bestScore then return candidateScore > bestScore end
    return tostring(candidate.id) < tostring(best.id)
end

local function assignCqbRoles(followers)
    for _, entry in ipairs(followers) do
        cqbMetrics(entry)
        entry.cqbRole = nil
        entry.roleIndex = nil
    end
    if #followers == 0 then return followers end

    local point
    for _, entry in ipairs(followers) do
        if betterRoleCandidate(entry, point, "pointScore") then point = entry end
    end
    point.cqbRole = "point"

    if #followers >= 2 then
        -- With at least three followers, preserve a firearm specialist for the
        -- protected middle whenever a non-ranged rear candidate exists.
        local rear, hasNonRanged = nil, false
        if #followers >= 3 then
            for _, entry in ipairs(followers) do
                if entry ~= point and not entry.rangedCapable then hasNonRanged = true break end
            end
        end
        for _, entry in ipairs(followers) do
            if entry ~= point and (not hasNonRanged or not entry.rangedCapable)
                and betterRoleCandidate(entry, rear, "rearScore") then rear = entry end
        end
        if rear == nil then
            for _, entry in ipairs(followers) do
                if entry ~= point and betterRoleCandidate(entry, rear, "rearScore") then rear = entry end
            end
        end
        if rear then rear.cqbRole = "rear_guard" end
    end

    for _, entry in ipairs(followers) do
        if entry.cqbRole == nil then
            entry.cqbRole = entry.rangedCapable and "ranged_support" or "assault"
        end
    end
    table.sort(followers, function(first, second)
        local firstRank = cqbRoleOrder[first.cqbRole] or 9
        local secondRank = cqbRoleOrder[second.cqbRole] or 9
        if firstRank ~= secondRank then return firstRank < secondRank end
        return tostring(first.id) < tostring(second.id)
    end)
    local counts = {}
    for index, entry in ipairs(followers) do
        counts[entry.cqbRole] = (counts[entry.cqbRole] or 0) + 1
        entry.roleIndex = counts[entry.cqbRole]
        entry.columnIndex = index
        entry.fireteamSize = #followers
    end
    return followers
end

local function stableCqbRoles(leaderState, key, followers, current)
    -- Compute the desired doctrine layout, then commit it only after roster
    -- membership has stayed unchanged. The live layout keeps vacancies briefly
    -- so one disconnect/death pulse cannot make everyone swap sides at once.
    assignCqbRoles(followers)
    leaderState.roleAssignments = leaderState.roleAssignments or {}
    local stable = leaderState.roleAssignments[key]
    local ids = {}
    for _, entry in ipairs(followers) do ids[#ids + 1] = tostring(entry.id) end
    table.sort(ids)
    local signature = table.concat(ids, "|")
    if not stable then
        stable = { assignments = {}, signature = signature }
        leaderState.roleAssignments[key] = stable
    elseif stable.signature == signature then
        stable.pendingSignature, stable.pendingSince = nil, nil
    elseif stable.signature ~= signature and stable.pendingSignature ~= signature then
        stable.pendingSignature, stable.pendingSince = signature, current
    end

    local roleStableMs = tonumber(U().config("formationRoleStableMs")) or 2000
    local vacancyGraceMs = tonumber(U().config("formationVacancyGraceMs")) or 1000
    local mayReflow = stable.pendingSignature == signature
        and current - (stable.pendingSince or current) >= roleStableMs
    local present, reservedSlots, reservedRoles = {}, {}, {}
    for _, entry in ipairs(followers) do present[entry.actor] = true end
    for actor, assignment in pairs(stable.assignments) do
        if present[actor] then
            assignment.lastSeen = current
        elseif current - (assignment.lastSeen or current) > vacancyGraceMs then
            stable.assignments[actor] = nil
        end
    end

    local hasAssignments = false
    for _ in pairs(stable.assignments) do hasAssignments = true break end
    if mayReflow or not hasAssignments then
        stable.assignments = {}
        for _, entry in ipairs(followers) do
            stable.assignments[entry.actor] = {
                role = entry.cqbRole, slot = entry.columnIndex, lastSeen = current,
            }
        end
        stable.signature = signature
        stable.pendingSignature, stable.pendingSince = nil, nil
    else
        for _, assignment in pairs(stable.assignments) do
            reservedSlots[assignment.slot] = true
            reservedRoles[assignment.role] = true
        end
        for _, entry in ipairs(followers) do
            local assignment = stable.assignments[entry.actor]
            if not assignment then
                local slot = 1
                while reservedSlots[slot] do slot = slot + 1 end
                local role = entry.cqbRole
                if (role == "point" or role == "rear_guard") and reservedRoles[role] then
                    role = entry.rangedCapable and "ranged_support" or "assault"
                end
                assignment = { role = role, slot = slot, lastSeen = current }
                stable.assignments[entry.actor] = assignment
                reservedSlots[slot], reservedRoles[role] = true, true
            end
            entry.cqbRole, entry.columnIndex = assignment.role, assignment.slot
        end
    end

    table.sort(followers, function(left, right)
        local leftSlot = stable.assignments[left.actor]
        local rightSlot = stable.assignments[right.actor]
        leftSlot = leftSlot and leftSlot.slot or math.huge
        rightSlot = rightSlot and rightSlot.slot or math.huge
        if leftSlot ~= rightSlot then return leftSlot < rightSlot end
        return tostring(left.id) < tostring(right.id)
    end)
    local counts = {}
    for _, entry in ipairs(followers) do
        local assignment = stable.assignments[entry.actor]
        entry.cqbRole = assignment and assignment.role or entry.cqbRole
        entry.columnIndex = assignment and assignment.slot or entry.columnIndex
        counts[entry.cqbRole] = (counts[entry.cqbRole] or 0) + 1
        entry.roleIndex = counts[entry.cqbRole]
        entry.fireteamSize = #followers
    end
    return followers
end

local function cqbOpenOffset(entry, slot)
    if type(entry) ~= "table" then
        return formationOffsets[((slot - 1) % #formationOffsets) + 1]
    end
    if entry.cqbRole == "point" then return { -1, 1 } end
    if entry.cqbRole == "rear_guard" then return { 0, 3 } end
    if entry.cqbRole == "ranged_support" then
        local side = (entry.roleIndex or 1) % 2 == 1 and 1 or -1
        local rank = math.floor(((entry.roleIndex or 1) - 1) / 2)
        return { side * (1 + rank), 2 + rank }
    end
    if entry.cqbRole == "assault" then
        if (entry.roleIndex or 1) == 1 then return { 1, 1 } end
        local side = (entry.roleIndex or 1) % 2 == 0 and -1 or 1
        return { side * 2, 1 + math.floor((entry.roleIndex or 1) / 2) }
    end
    return formationOffsets[((slot - 1) % #formationOffsets) + 1]
end

local function rosterGroupKey(group)
    return group == nil and "__ungrouped" or "group:" .. tostring(group)
end

local function followerRoster(leader, current, group)
    local utility = U()
    local leaderState = leaderStateFor(leader)
    if current >= (leaderState.fireteamsExpires or 0) then
        local fireteams = {}
        -- Partition the whole recruited roster once per leader pulse. Selecting
        -- Alpha, Bravo and an ungrouped follower in the same frame must not turn
        -- into three registry scans.
        for _, other in ipairs(utility.registryLiving(utility.config("maxCompanions") or 16)) do
            local commands = commandState(other)
            if commands and commands.recruited
                and (commands.order == "follow" or commands.order == "regroup") then
                local key = rosterGroupKey(commands.group)
                local bucket = fireteams[key]
                if not bucket then
                    bucket = {}
                    fireteams[key] = bucket
                end
                bucket[#bucket + 1] = {
                    actor = other, id = utility.idOf(other), commands = commands,
                }
            end
        end
        for key, followers in pairs(fireteams) do
            table.sort(followers, function(a, b) return tostring(a.id) < tostring(b.id) end)
            stableCqbRoles(leaderState, key, followers, current)
            local slots = setmetatable({}, { __mode = "k" })
            for index, value in ipairs(followers) do
                -- The dense array index is the lookup key; columnIndex may retain
                -- a one-second vacancy by design.
                slots[value.actor] = index
            end
            fireteams[key] = { roster = followers, slots = slots }
        end
        leaderState.fireteams = fireteams
        leaderState.fireteamsExpires = current + 250
    end
    local cached = leaderState.fireteams and leaderState.fireteams[rosterGroupKey(group)] or nil
    if cached then return cached.roster, cached.slots end
    return emptyFireteam, emptyFireteamSlots
end

local function followerSlot(actor, leader, current)
    local commands = commandState(actor)
    local followers, slots = followerRoster(leader, current,
        commands and commands.group or nil)
    if slots[actor] then
        local entry = followers[slots[actor]]
        return entry.columnIndex or slots[actor], followers, entry
    end
    return (U().stableHash(U().idOf(actor)) % #formationOffsets) + 1, followers, nil
end

local function cohortKey(actor, leader)
    if SC.Factions and type(SC.Factions.affiliation) == "function" then
        local ok, affiliation = pcall(SC.Factions.affiliation, actor)
        if ok and type(affiliation) == "table" and affiliation.factionId then
            return "faction:" .. tostring(affiliation.factionId)
        end
    end
    return "party:" .. tostring(U().idOf(leader))
end

local function sampleLeader(leader, current, roster, cohort)
    local utility = U()
    local state = leaderStateFor(leader)
    local x, y = utility.position(leader)
    local square = utility.squareOf(leader)
    if not x or not square then return state end
    local _, _, z = utility.position(square)
    local vehicle = select(1, utility.call(leader, "getVehicle"))

    if state.leaderX ~= nil then
        local elapsed = current - (state.leaderSampleAt or current)
        local deltaX, deltaY = x - state.leaderX, y - state.leaderY
        local jumpSq = deltaX * deltaX + deltaY * deltaY
        local discontinuity = jumpSq > 36 or vehicle ~= state.vehicle
        if discontinuity then
            state.trail = {}
            state.revision = (state.revision or 0) + 1
            state.totalDistance = 0
            state.latestPortal = nil
            state.latestPortalAt = nil
            state.portalPassageActive = false
            state.portalReflowUntil = nil
            state.velocityX, state.velocityY = 0, 0
        end
        local velocityX, velocityY
        if not discontinuity then velocityX, velocityY = normalized(deltaX, deltaY) end
        if velocityX ~= nil then
            state.headingX, state.headingY = velocityX, velocityY
            state.headingAt = current
            if elapsed > 0 and elapsed <= 1000 then
                local sampleX, sampleY = deltaX / elapsed, deltaY / elapsed
                -- Smooth one noisy world-position sample without lagging far behind
                -- a genuine turn. Values are tiles/ms and are capped below when used.
                state.velocityX = state.velocityX == nil and sampleX
                    or state.velocityX * 0.35 + sampleX * 0.65
                state.velocityY = state.velocityY == nil and sampleY
                    or state.velocityY * 0.35 + sampleY * 0.65
            end
        elseif elapsed > 0 then
            state.velocityX = (state.velocityX or 0) * 0.35
            state.velocityY = (state.velocityY or 0) * 0.35
        end
    end
    local last = state.trail[#state.trail]
    local shouldSample = not last
    if last then
        local dx, dy = x - last.x, y - last.y
        shouldSample = current - (last.at or 0) >= 100
            and (dx * dx + dy * dy >= 0.35 * 0.35
                or math.floor(z or 0) ~= math.floor(last.z or 0))
    end
    if shouldSample then
        local distance = 0
        local edge
        if last then
            local dx, dy = x - last.x, y - last.y
            distance = math.sqrt(dx * dx + dy * dy)
            if SC.Navigation and type(SC.Navigation.edgeAffordance) == "function" then
                edge = SC.Navigation.edgeAffordance(last.square, square)
            end
        end
        state.totalDistance = (state.totalDistance or 0) + distance
        local point = {
            x = x, y = y, z = z, square = square, at = current,
            distance = state.totalDistance, edge = edge,
        }
        state.trail[#state.trail + 1] = point
        local limit = math.max(12, tonumber(utility.config("navigationBreadcrumbLimit")) or 64)
        while #state.trail > limit do table.remove(state.trail, 1) end
        state.revision = (state.revision or 0) + 1
        if edge and (edge.kind == "door" or edge.kind == "stairs") then
            state.latestPortal = edge
            state.latestPortalAt = current
            if SC.Navigation and type(SC.Navigation.observeGroupPassage) == "function" then
                pcall(SC.Navigation.observeGroupPassage, leader, edge, cohort, roster, current)
            end
        end
    end
    state.leaderX, state.leaderY, state.leaderZ = x, y, z
    state.leaderSquare, state.leaderSampleAt, state.vehicle = square, current, vehicle

    -- Turning to aim while standing still must not make the whole formation
    -- orbit the player. Native facing is only adopted before a travel heading
    -- exists or after a long stationary interval.
    if state.headingX == nil or current - (state.headingAt or 0) > 2500 then
        local forwardX, forwardXOk = utility.call(leader, "getForwardDirectionX")
        local forwardY, forwardYOk = utility.call(leader, "getForwardDirectionY")
        if forwardXOk and forwardYOk then
            local normalizedX, normalizedY = normalized(forwardX, forwardY)
            if normalizedX ~= nil then
                state.headingX, state.headingY = normalizedX, normalizedY
                state.headingAt = current
            end
        end
    end
    return state
end

local function leaderHeading(actor, leader, current)
    local commands = commandState(actor)
    local roster = followerRoster(leader, current, commands and commands.group or nil)
    local state = sampleLeader(leader, current, roster, cohortKey(actor, leader))
    return state.headingX or 0, state.headingY or -1,
        state.velocityX or 0, state.velocityY or 0
end

local function reservationKey(square)
    return U().squareKey(square)
end

local function sweepReservations(current)
    if current < nextReservationSweepAt then return end
    for key, reservation in pairs(targetReservations) do
        if not reservation or reservation.expires <= current then targetReservations[key] = nil end
    end
    nextReservationSweepAt = current + 3000
end

local function canReserve(actor, square, current)
    local key = reservationKey(square)
    if not key then return false end
    local existing = targetReservations[key]
    if existing and existing.actor ~= actor and existing.expires > current then return false end
    targetReservations[key] = {
        actor = actor,
        expires = current + (U().config("positioningReservationMs") or 650),
    }
    local state = stateFor(actor)
    if state.reservationKey and state.reservationKey ~= key then
        local previous = targetReservations[state.reservationKey]
        if previous and previous.actor == actor then targetReservations[state.reservationKey] = nil end
    end
    state.reservationKey = key
    return true
end

local function allyClear(actor, square, snapshot, minimum)
    if not square then return false end
    local minimumSq = minimum * minimum
    if type(snapshot) == "table" then
        for _, ally in ipairs(snapshot.allies or {}) do
            if ally.actor and ally.actor ~= actor and U().sameFloor(ally.actor, square)
                and U().distanceSq(ally.actor, square) < minimumSq then return false end
        end
        local player = snapshot.player
        if type(player) == "table" and player.actor and player.actor ~= actor
            and U().sameFloor(player.actor, square)
            and U().distanceSq(player.actor, square) < minimumSq then return false end
    end
    return true
end

local candidateDeltas = {
    { 0, 0 }, { -1, 0 }, { 1, 0 }, { 0, 1 }, { 0, -1 },
    { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 },
}

local function availableTarget(actor, x, y, z, snapshot, minimum, predicate)
    local utility = U()
    local current = utility.nowMs()
    sweepReservations(current)
    local start = (utility.stableHash(utility.idOf(actor)) % (#candidateDeltas - 1)) + 2
    local ordered = { candidateDeltas[1] }
    for offset = 0, #candidateDeltas - 2 do
        ordered[#ordered + 1] = candidateDeltas[((start - 2 + offset) % (#candidateDeltas - 1)) + 2]
    end
    for _, delta in ipairs(ordered) do
        local square = utility.gridSquare(x + delta[1], y + delta[2], z)
        if square and utility.isSquareFree(square) and allyClear(actor, square, snapshot, minimum)
            and (type(predicate) ~= "function" or predicate(square))
            and canReserve(actor, square, current) then return square end
    end
    return nil
end

local function trailTarget(actor, leaderState, lagDistance, snapshot, minimum, current)
    local utility = U()
    local trail = leaderState.trail or {}
    local latest = trail[#trail]
    if not latest then return nil, nil end
    local selectedIndex = 1
    for index = #trail, 1, -1 do
        selectedIndex = index
        if (latest.distance or 0) - (trail[index].distance or 0) >= lagDistance then break end
    end
    -- Prefer the chosen breadcrumb itself. If another follower owns it, walk
    -- backwards along the exact leader trail instead of cutting a corner.
    sweepReservations(current)
    for index = selectedIndex, math.max(1, selectedIndex - 4), -1 do
        local point = trail[index]
        local square = point and point.square or nil
        if square and utility.isSquareFree(square) and allyClear(actor, square, snapshot, minimum)
            and canReserve(actor, square, current) then
            return square, point.edge
        end
    end
    local point = trail[selectedIndex]
    if not point then return nil, nil end
    return availableTarget(actor, point.x, point.y, point.z, snapshot, minimum), point.edge
end

function Positioning.formationTarget(actor, leader, commands, snapshot)
    local utility = U()
    local px, py, pz = utility.position(leader)
    if not px then return nil end
    local current = utility.nowMs()
    local slot, roster, fireteamMember = followerSlot(actor, leader, current)
    local cohort = cohortKey(actor, leader)
    local leaderState = sampleLeader(leader, current, roster, cohort)
    local forwardX, forwardY = leaderState.headingX or 0, leaderState.headingY or -1
    local velocityX, velocityY = leaderState.velocityX or 0, leaderState.velocityY or 0
    local rightX, rightY = -forwardY, forwardX
    local localOffset = cqbOpenOffset(fireteamMember, slot)
    local scale = commands.order == "regroup" and 0.75
        or math.max(0.75, (tonumber(commands.followDistance) or 3) / 3)
    local predictionX, predictionY = 0, 0
    local moving, movingOk = utility.call(leader, "isMoving")
    if movingOk and moving == true then
        local leadMs = math.max(0, tonumber(utility.config("formationPredictionMs")) or 250)
        predictionX, predictionY = velocityX * leadMs, velocityY * leadMs
        local predictionLength = math.sqrt(predictionX * predictionX + predictionY * predictionY)
        local maximumLead = math.max(0,
            tonumber(utility.config("formationPredictionMaxDistance")) or 1.25)
        if predictionLength > maximumLead and predictionLength > 0.001 then
            local scaleDown = maximumLead / predictionLength
            predictionX, predictionY = predictionX * scaleDown, predictionY * scaleDown
        end
    end
    local targetX = px + predictionX
        + rightX * localOffset[1] * scale - forwardX * localOffset[2] * scale
    local targetY = py + predictionY
        + rightY * localOffset[1] * scale - forwardY * localOffset[2] * scale
    local minimum = utility.config("formationSeparation") or 1.25
    local state = stateFor(actor)
    local distanceToLeader = utility.distance(actor, leader)
    local clearOpenFormation = utility.sameFloor(actor, leader)
        and distanceToLeader <= (tonumber(utility.config("formationOpenDistance")) or 6)
        and (utility.canSee(actor, leader)
            or utility.canSee(actor, utility.squareOf(leader)))
    local portalHoldMs = tonumber(utility.config("formationPortalHoldMs")) or 1200
    local passageActive = false
    if leaderState.latestPortal and SC.Navigation
        and type(SC.Navigation.groupPassageActive) == "function" then
        local ok, active = pcall(SC.Navigation.groupPassageActive,
            leaderState.latestPortal, cohort, current)
        passageActive = ok and active == true
    end
    if passageActive then
        leaderState.portalPassageActive = true
        leaderState.portalReflowUntil = nil
    elseif leaderState.portalPassageActive then
        leaderState.portalPassageActive = false
        leaderState.portalReflowUntil = current
            + (tonumber(utility.config("formationReflowDelayMs")) or 650)
    end
    local portalColumnUntil = math.max(
        tonumber(leaderState.portalReflowUntil) or 0,
        (tonumber(leaderState.latestPortalAt) or -portalHoldMs) + portalHoldMs)
    local portalColumn = passageActive or current < portalColumnUntil
    if portalColumn then
        clearOpenFormation = false
    end
    if not clearOpenFormation then
        if portalColumn then
            state.trailModeUntil = math.max(tonumber(state.trailModeUntil) or 0,
                portalColumnUntil)
        else
            state.trailModeUntil = current + portalHoldMs
        end
    end
    local mode = clearOpenFormation and current >= (state.trailModeUntil or 0)
        and "open" or "trail"
    local target, portal
    if mode == "trail" then
        local trail = leaderState.trail or {}
        if #trail >= 2 and (leaderState.totalDistance or 0) >= 0.35 then
            local lag = 1.5 + math.max(0, slot - 1) * 1.1
            target, portal = trailTarget(actor, leaderState, lag, snapshot, minimum, current)
        else
            -- Immediately after loading, the in-memory breadcrumb trail contains
            -- only the leader's current square. It does not describe the doorway
            -- or corner between an outdoor follower and an indoor player. Route to
            -- a free square beside the leader as a bootstrap goal, but keep this
            -- distinct from open formation so Navigation never treats wall-blocked
            -- startup as an ordinary lateral formation adjustment.
            mode = "bootstrap"
            target = availableTarget(actor, px, py, pz, snapshot, minimum)
        end
    end
    if not target then
        if mode == "open" then
            target = availableTarget(actor, targetX, targetY, pz, snapshot, minimum)
        else
            mode = "bootstrap"
            target = availableTarget(actor, px, py, pz, snapshot, minimum)
        end
    end
    local previous = state.targetSquare
    local retainDistance = tonumber(utility.config("formationTargetHysteresisDistance")) or 1.1
    if mode == "open" and target and previous and reservationKey(previous) ~= reservationKey(target)
        and utility.sameFloor(previous, target)
        and utility.distance(previous, target) <= retainDistance
        and utility.isSquareFree(previous) and allyClear(actor, previous, snapshot, minimum)
        and canReserve(actor, previous, current) then
        -- The continuous ideal point often straddles a tile boundary as a player
        -- slows or turns. Keep the previous valid slot across one neighbouring
        -- tile; release it once the formation has genuinely moved farther away.
        target = previous
    end
    if target then
        state.slot = slot
        state.targetKey = reservationKey(target)
        state.targetSquare = target
        state.predictionX, state.predictionY = predictionX, predictionY
        state.predictionDistance = math.sqrt(predictionX * predictionX + predictionY * predictionY)
        state.formationMode = mode
        state.trailRevision = leaderState.revision or 0
        state.portalKey = portal and portal.key or nil
        state.columnIndex = slot
        state.cqbRole = fireteamMember and fireteamMember.cqbRole or nil
        state.fireteamSize = fireteamMember and fireteamMember.fireteamSize or #roster
        state.cohortKey = cohort
        state.velocityX, state.velocityY = velocityX, velocityY
    end
    return target, {
        mode = mode,
        trailRevision = leaderState.revision or 0,
        portalKey = portal and portal.key or nil,
        portal = portal,
        columnIndex = slot,
        cqbRole = fireteamMember and fireteamMember.cqbRole or nil,
        fireteamSize = fireteamMember and fireteamMember.fireteamSize or #roster,
        cohortKey = cohort,
        participants = roster,
    }
end

function Positioning.cohortKey(actor, leader)
    return cohortKey(actor, leader)
end

function Positioning.cqbRole(actor, leader)
    if not actor or not leader then return nil end
    local current = U().nowMs()
    local commands = commandState(actor)
    local followers, slots = followerRoster(leader, current,
        commands and commands.group or nil)
    local slot = slots[actor]
    local entry = slot and followers[slot] or nil
    return entry and entry.cqbRole or nil,
        entry and entry.columnIndex or slot, #followers
end

function Positioning.shouldHold(actor, target)
    if not actor or not target then return false end
    local state = stateFor(actor)
    local enter = U().config("formationArrivalDistance") or 0.9
    local leave = math.max(enter + 0.25, U().config("formationReleaseDistance") or 1.55)
    local withinLeave, distance = U().arrived(actor, target, {
        targetKind = "square", distance = leave,
    })
    if state.holdingFormation then
        if withinLeave then return true end
        state.holdingFormation = false
        return false
    end
    local withinEnter = distance <= enter
    if withinEnter then
        state.holdingFormation = true
        state.heldAt = U().nowMs()
        return true
    end
    return false
end

local function booleanState(character, method, variable)
    if not character then return false end
    local value, ok = U().call(character, method)
    if ok then return value == true end
    if variable then
        value, ok = U().call(character, "getVariableBoolean", variable)
        if ok then return value == true end
    end
    return false
end

function Positioning.playerMoveMode(player)
    if not player then return "walk" end
    if booleanState(player, "isSneaking", "isSneaking")
        or booleanState(player, "isCrouching", "isCrouching") then
        return "sneak"
    end
    if booleanState(player, "isSprinting", "isSprinting")
        or booleanState(player, "isRunning", "isRunning") then
        return "jog"
    end
    return "walk"
end

function Positioning.resolveMoveMode(requested, player)
    if requested == "copy" then return Positioning.playerMoveMode(player) end
    if requested == "jog" or requested == "sneak" then return requested end
    return "walk"
end

function Positioning.syncCopiedPosture(actor, player, requested)
    if requested ~= "copy" then return nil, "posture_not_copied" end
    local sneaking = Positioning.playerMoveMode(player) == "sneak"
    return U().move(actor, "walk", {
        action = "copy_player_posture",
        sneaking = sneaking,
        humanAnimationOnly = true,
    })
end

function Positioning.followMode(requested, stress, leaderDistance, player)
    local mode = Positioning.resolveMoveMode(requested, player)
    local far = U().config("followFarDistance") or 18
    if leaderDistance >= far then return "jog", "catch_up" end
    if leaderDistance > 8 and mode == "sneak" then return "walk", "closing_distance" end
    if requested ~= "copy" and tonumber(stress) and tonumber(stress) >= 72
        and leaderDistance <= 8 then
        return "sneak", "guarded"
    end
    return mode, tonumber(stress) and tonumber(stress) >= 42 and "alert" or "calm"
end

function Positioning.updateHoldAwareness(actor, leader, snapshot)
    local utility = U()
    if not utility.isValidActor(actor) or not utility.isValidActor(leader) then
        return false, "invalid_awareness_actor"
    end
    if type(snapshot) == "table" and ((tonumber(snapshot.threatCount) or 0) > 0
        or (tonumber(snapshot.immediateCount) or 0) > 0) then return nil, "danger_present" end

    local state = stateFor(actor)
    local current = utility.nowMs()
    local forwardX, forwardY = leaderHeading(actor, leader, current)
    local actorX, actorY, actorZ = utility.position(actor)
    if not actorX then return false, "awareness_position_unavailable" end

    if state.cqbRole == "rear_guard" then
        local interval = utility.config("rearGuardRefreshMs") or 2200
        if not utility.isDue(actor, "formation_rear_guard", interval, current) then
            return nil, "rear_guard_watch_not_due"
        end
        if not utility.stop(actor) then return false, "rear_guard_stop_rejected" end
        local accepted, reason = utility.move(actor, "walk", {
            action = "rear_guard_watch",
            targetPosition = {
                x = actorX - forwardX * 2,
                y = actorY - forwardY * 2,
                z = actorZ,
            },
            stableFacing = true,
            awarenessMovement = true,
            cqbRole = "rear_guard",
        })
        return accepted == true, reason or "rear_guard_watch_rejected"
    end

    if state.restoreFormationFacingAt then
        if current < state.restoreFormationFacingAt then return true, "rear_scan_observing" end
        local accepted, reason = utility.move(actor, "walk", {
            action = "face_formation",
            targetPosition = {
                x = actorX + forwardX * 2,
                y = actorY + forwardY * 2,
                z = actorZ,
            },
            stableFacing = true,
            awarenessMovement = true,
        })
        if accepted then state.restoreFormationFacingAt = nil end
        return accepted == true, reason or "formation_facing_restore_rejected"
    end

    local interval = utility.config("rearScanIntervalMs") or 8500
    if not utility.isDue(actor, "formation_rear_scan", interval, current) then
        return nil, "rear_scan_not_due"
    end
    if not utility.stop(actor) then return false, "rear_scan_stop_rejected" end
    local accepted, reason = utility.move(actor, "walk", {
        action = "rear_scan",
        targetPosition = {
            x = actorX - forwardX * 2,
            y = actorY - forwardY * 2,
            z = actorZ,
        },
        stableFacing = true,
        awarenessMovement = true,
    })
    if accepted then
        state.restoreFormationFacingAt = current + (utility.config("rearScanHoldMs") or 550)
    end
    return accepted == true, reason or "rear_scan_rejected"
end

local function conversationTarget(actor, partner, snapshot)
    local utility = U()
    local px, py, pz = utility.position(partner)
    local ax, ay = utility.position(actor)
    if not px or not ax then return nil end
    local awayX, awayY = normalized(ax - px, ay - py)
    if awayX == nil then
        local hash = utility.stableHash(utility.idOf(actor)) % 4
        local directions = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
        awayX, awayY = directions[hash + 1][1], directions[hash + 1][2]
    end
    local radius = utility.config("conversationPreferredDistance") or 1.65
    local minimum = utility.config("conversationMinimumDistance") or 1.2
    local maximum = utility.config("conversationMaximumDistance") or 2.8
    return availableTarget(actor, px + awayX * radius, py + awayY * radius, pz,
        snapshot, utility.config("conversationCompanionSpacing") or 1.15, function(square)
            local distance = utility.distance(square, partner)
            return distance >= minimum and distance <= maximum
        end)
end

function Positioning.beginConversation(actor, partner, options)
    local utility = U()
    if not utility.isValidActor(actor) or not utility.isValidActor(partner) then
        return false, "invalid_conversation_actor"
    end
    local state = stateFor(actor)
    local current = utility.nowMs()
    state.conversation = {
        partner = partner,
        action = type(options) == "table" and options.action or nil,
        emote = type(options) == "table" and options.emote or nil,
        stress = type(options) == "table" and tonumber(options.stress) or 0,
        expires = current + (utility.config("conversationHoldMs") or 5000),
        posed = false,
    }
    return true, "conversation_staged"
end

function Positioning.activeConversation(actor)
    local state = actor and states[actor] or nil
    local conversation = state and state.conversation or nil
    if not conversation then return nil end
    if U().nowMs() >= (conversation.expires or 0)
        or not U().isValidActor(conversation.partner) then
        state.conversation = nil
        return nil
    end
    return conversation
end

function Positioning.updateConversation(actor, snapshot)
    local utility = U()
    local conversation = Positioning.activeConversation(actor)
    if not conversation then return false, "no_conversation" end
    if type(snapshot) == "table" and ((tonumber(snapshot.threatCount) or 0) > 0
        or (tonumber(snapshot.immediateCount) or 0) > 0) then
        stateFor(actor).conversation = nil
        return false, "conversation_interrupted_by_danger"
    end

    local partner = conversation.partner
    local minimum = utility.config("conversationMinimumDistance") or 1.2
    local maximum = utility.config("conversationMaximumDistance") or 2.8
    local partnerDistance = utility.distance(actor, partner)
    if not utility.sameFloor(actor, partner) or partnerDistance > maximum
        or partnerDistance < minimum then
        local target = conversationTarget(actor, partner, snapshot)
        if not target then return false, "conversation_position_unavailable" end
        if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            return false, "conversation_navigation_unavailable"
        end
        return SC.Navigation.request(actor, target, "walk", {
            action = "conversation_approach",
            targetSquare = target,
            snapshot = snapshot,
            socialMovement = true,
        })
    end

    if not utility.stop(actor) then return false, "conversation_stop_rejected" end
    local action = conversation.posed and "face_conversation" or "conversation_pose"
    local emote = conversation.emote
    if not conversation.posed and (type(emote) ~= "string" or emote == "") then
        if conversation.stress >= 72 then emote = "undecided"
        elseif conversation.stress >= 42 then emote = "shrug"
        else emote = "yes" end
    end
    local accepted, reason = utility.move(actor, "walk", {
        action = action,
        targetPosition = partner,
        emote = not conversation.posed and emote or nil,
        socialMovement = true,
        stableFacing = true,
        stressPosture = conversation.stress >= 72 and "shaken"
            or conversation.stress >= 42 and "uneasy" or "calm",
    })
    if accepted then conversation.posed = true end
    return accepted == true, reason or (accepted and "conversation_facing" or "conversation_pose_rejected")
end

function Positioning.debug(actor)
    local state = actor and states[actor] or nil
    if not state then return nil end
    return {
        slot = state.slot,
        targetKey = state.targetKey,
        holdingFormation = state.holdingFormation == true,
        predictionDistance = state.predictionDistance or 0,
        velocityX = state.velocityX or 0,
        velocityY = state.velocityY or 0,
        formationMode = state.formationMode,
        trailRevision = state.trailRevision,
        portalKey = state.portalKey,
        columnIndex = state.columnIndex,
        cqbRole = state.cqbRole,
        fireteamSize = state.fireteamSize,
        cohortKey = state.cohortKey,
        conversation = state.conversation and {
            action = state.conversation.action,
            posed = state.conversation.posed == true,
            expires = state.conversation.expires,
        } or nil,
    }
end

function Positioning.reset(actor)
    if actor then
        local state = states[actor]
        if state and state.reservationKey then
            local reservation = targetReservations[state.reservationKey]
            if reservation and reservation.actor == actor then targetReservations[state.reservationKey] = nil end
        end
        states[actor] = nil
        leaderStates[actor] = nil
    else
        states = setmetatable({}, { __mode = "k" })
        leaderStates = setmetatable({}, { __mode = "k" })
        targetReservations = {}
        nextReservationSweepAt = 0
    end
end

return Positioning
