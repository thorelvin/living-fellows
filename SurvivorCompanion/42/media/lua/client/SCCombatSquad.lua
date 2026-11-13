-- SPDX-License-Identifier: MIT
-- Short-lived local coordination. Sensing and native combat remain authoritative.
local SC = SurvivorCompanion
SC.CombatSquad = SC.CombatSquad or {}
local Squad = SC.CombatSquad

local plans = {}
local probeFrame, probes = nil, 0

local function U() return SC.GameplayUtil end
local function position(value)
    return U().position(value)
end
local function distanceSq(ax, ay, bx, by)
    return (ax - bx) ^ 2 + (ay - by) ^ 2
end
local function expeditionMember(actor)
    return SC.ExpeditionPrototype and type(SC.ExpeditionPrototype.isMember) == "function"
        and SC.ExpeditionPrototype.isMember(actor) == true or false
end
local function sameGroup(left, right)
    return expeditionMember(left) == expeditionMember(right)
        and U().sameFloor(left, right)
end

function Squad.positionProbe(now)
    local runtime = SC.Runtime
    local frame = runtime and type(runtime.frameSerial) == "function"
        and runtime.frameSerial() or math.floor((now or U().nowMs()) / 16)
    if frame ~= probeFrame then probeFrame, probes = frame, 0 end
    if probes >= 8 then return false end
    probes = probes + 1
    return true
end

-- What one member can bring to a fight now, from its own state alone. It
-- makes no group calls, so judging an ally never recurses into the squad.
-- A member that is grabbed, seated, exhausted, downed or without a usable
-- weapon or fighting response is not a defender, whatever its health.
function Squad.capability(actor, health)
    local utility = U()
    if not actor or utility.isDead(actor) then return { ready = false, reason = "dead" } end
    if (tonumber(health) or 100) <= 50 then return { ready = false, reason = "hurt" } end
    if SC.Medical and type(SC.Medical.isDowned) == "function"
        and SC.Medical.isDowned(actor) then return { ready = false, reason = "downed" } end
    if utility.characterStatValue(actor, "ENDURANCE", 0.5) <= 0.25 then
        return { ready = false, reason = "exhausted" }
    end
    if select(1, utility.call(actor, "getVehicle")) ~= nil then
        return { ready = false, reason = "seated" }
    end
    if SC.ZombieAttack and type(SC.ZombieAttack.isGrabbed) == "function"
        and SC.ZombieAttack.isGrabbed(actor) == true then
        return { ready = false, reason = "grabbed" }
    end
    local combat, weapon = SC.Combat, nil
    if combat and type(combat.primaryWeaponUsable) == "function"
        and combat.primaryWeaponUsable(actor) == true then
        weapon = "armed"
    elseif combat and type(combat.unarmedResponse) == "function"
        and combat.unarmedResponse(actor) == "fight" then
        weapon = "unarmed"
    else
        return { ready = false, reason = "no_weapon" }
    end
    -- Stay and guard keep a companion near its spot. Read the saved order:
    -- Commands.peek creates state as a side effect.
    local data, anchor = utility.modData(actor), nil
    if type(data) == "table" and (data.SC_Order == "stay" or data.SC_Order == "guard")
        and type(data.SC_AnchorX) == "number" and type(data.SC_AnchorY) == "number" then
        anchor = { x = data.SC_AnchorX, y = data.SC_AnchorY }
    end
    return { ready = true, weapon = weapon, anchor = anchor }
end

local function anchorReaches(member, x, y)
    local anchor = member.capability and member.capability.anchor
    if not anchor then return true end
    local reach = (tonumber(U().config("guardRadius")) or 5) + 1
    return distanceSq(anchor.x + 0.5, anchor.y + 0.5, x, y) <= reach * reach
end

local function collectMembers(actor, snapshot, cohort, x, y, z)
    local actorHealth = U().nativeHealth(actor)
    local party = string.sub(tostring(cohort), 1, 6) == "party:"
    local own = Squad.capability(actor, actorHealth)
    local members = {
        { actor = actor, x = x, y = y, z = z,
            health = actorHealth, capable = own.ready, capability = own },
    }
    for _, ally in ipairs(snapshot.allies or {}) do
        if #members >= 16 then break end
        local other = ally.actor
        if other and (ally.relationship == nil
            or (party and ally.relationship == "party_ally")
            or (not party and ally.relationship == "faction_ally"))
            and sameGroup(actor, other) and U().isValidActor(other) then
            local ox, oy, oz = position(other)
            if ox and distanceSq(x, y, ox, oy) <= 36 then
                local health = tonumber(ally.health) or U().nativeHealth(other)
                local profile = Squad.capability(other, health)
                members[#members + 1] = { actor = other, x = ox, y = oy,
                    z = oz, health = health, capable = profile.ready,
                    capability = profile }
            end
        end
    end
    return members
end

-- A member's own latest sensing snapshot, when it is fresh. The plan is the
-- encounter's, not the view of whichever companion happened to rebuild it: a
-- zombie only the far member can see still belongs in it. No new scans.
local function memberSnapshot(member, now)
    local registry = SC.Registry
    if type(registry) ~= "table" or type(registry.idOf) ~= "function"
        or type(registry.byId) ~= "function" then return nil end
    local id = registry.idOf(member)
    local record = id and registry.byId(id) or nil
    local runtime = type(record) == "table" and record.runtime or nil
    local senses = type(runtime) == "table" and runtime.senses or nil
    local snapshot = type(senses) == "table" and senses.current or nil
    local observed = type(snapshot) == "table" and tonumber(snapshot.time) or nil
    if observed == nil or observed > now + 1000 or now - observed > 500 then return nil end
    return snapshot
end

local function nearestMemberSq(members, tx, ty)
    local best
    for _, member in ipairs(members) do
        local d2 = distanceSq(member.x, member.y, tx, ty)
        if best == nil or d2 < best then best = d2 end
    end
    return best or math.huge
end

local function collectThreats(views, members, player, z)
    local threats, seen = {}, {}
    for _, snapshot in ipairs(views) do
        for index, threat in ipairs(snapshot.threats or {}) do
            if index > 64 then break end
            local other = threat.actor
            if other and not seen[other] and not U().isDead(other)
                and threat.obstructed ~= true and threat.visible ~= false then
                local tx, ty, tz = tonumber(threat.x), tonumber(threat.y), tonumber(threat.z)
                if not tx then tx, ty, tz = position(other) end
                if tx and (tz == nil or math.floor(tz) == math.floor(z)) then
                    local facts = SC.ZombieFacts and SC.ZombieFacts.get(other) or nil
                    local posture = facts and facts.posture or threat.posture
                    if posture ~= "downed" or (facts and facts.gettingUp) then
                        local d2 = nearestMemberSq(members, tx, ty)
                        local arriving = tonumber(threat.timeToImpactMs)
                        local horizon = tonumber(U().config("combatSquadArrivalZeroMs")) or 8000
                        if (posture ~= "crawler" or d2 <= 2 * 2
                            or (arriving ~= nil and arriving <= horizon))
                            and (d2 <= 6 * 6 or (d2 <= 12 * 12
                                and arriving ~= nil and arriving <= horizon)) then
                            seen[other] = true
                            local victim = facts and facts.target or threat.target
                            -- Anything on the player, or on a companion that is
                            -- held, is everyone's first job.
                            local onPlayer = victim ~= nil and player ~= nil and victim == player
                            local onGrabbed = victim ~= nil and not onPlayer and SC.ZombieAttack
                                and type(SC.ZombieAttack.isGrabbed) == "function"
                                and SC.ZombieAttack.isGrabbed(victim) == true
                            local priority = (onPlayer and 80 or onGrabbed and 60
                                    or threat.attacking and 50 or victim and 25 or 0)
                                + 30 / (1 + math.sqrt(d2))
                                + math.max(0, 5 - (arriving or 99999) / 1000) * 3
                            threats[#threats + 1] = { actor = other, x = tx, y = ty,
                                distanceSq = d2, victim = victim, priority = priority,
                                urgent = onPlayer or onGrabbed or threat.attacking == true,
                                attacking = threat.attacking == true,
                                crawler = posture == "crawler", arrivingMs = arriving,
                                incoming = arriving ~= nil and arriving <= 5000 }
                        end
                    end
                end
            end
        end
    end
    table.sort(threats, function(a, b)
        if a.priority == b.priority then return a.distanceSq < b.distanceSq end
        return a.priority > b.priority
    end)
    while #threats > 64 do table.remove(threats) end
    return threats
end

local function reaches(member, threat)
    return distanceSq(member.x, member.y, threat.x, threat.y) <= 6 * 6
end

-- Who fights which zombie. Every reachable zombie gets one defender before any
-- gets a second, zombies on the player or on a held companion come first, and
-- a companion already fighting a zombie keeps it. Members are taken in id
-- order, so the same scene always gives the same plan.
local function assign(members, threats)
    local owner, held = {}, {}
    local function give(member, threat)
        local previous = held[member]
        if previous then owner[previous] = nil end
        held[member], owner[threat] = threat, member
    end
    local function nearestFree(threat, allowed)
        local best, bestScore
        for _, member in ipairs(members) do
            if member.capable and reaches(member, threat)
                and (held[member] == nil or allowed and allowed(member)) then
                local score = distanceSq(member.x, member.y, threat.x, threat.y)
                    - (threat.victim == member.actor and 3 or 0)
                if bestScore == nil or score < bestScore then best, bestScore = member, score end
            end
        end
        return best
    end
    local byActor = {}
    for _, threat in ipairs(threats) do byActor[threat.actor] = threat end
    local combat = SC.Combat
    if combat and type(combat.peek) == "function" then
        for _, member in ipairs(members) do
            local state = member.capable and combat.peek(member.actor) or nil
            local threat = type(state) == "table" and state.target and byActor[state.target] or nil
            if threat and not owner[threat] and reaches(member, threat) then give(member, threat) end
        end
    end
    for pass = 1, 2 do
        for _, threat in ipairs(threats) do
            if (threat.urgent == true) == (pass == 1) and not owner[threat] then
                local member = nearestFree(threat)
                if not member and pass == 1 then
                    member = nearestFree(threat, function(candidate)
                        return held[candidate].urgent ~= true
                    end)
                end
                if member then give(member, threat) end
            end
        end
    end
    -- Cover before doubling: an uncovered zombie may take a member whose own
    -- zombie a free member can take over. One exchange per zombie, bounded.
    for _, threat in ipairs(threats) do
        if not owner[threat] then
            local best, bestD2, relief
            for _, member in ipairs(members) do
                local mine = held[member]
                if mine and mine.urgent ~= true and member.capable and reaches(member, threat) then
                    local free = nearestFree(mine)
                    local d2 = distanceSq(member.x, member.y, threat.x, threat.y)
                    if free and (bestD2 == nil or d2 < bestD2) then
                        best, bestD2, relief = member, d2, free
                    end
                end
            end
            if best then
                local mine = held[best]
                give(best, threat)
                give(relief, mine)
            end
        end
    end
    return held
end

local DOCTRINE_SHIFT = { weapons_free = 1, ranged_support = -1 }

-- How many zombies this member can hold at once: two when fit, one when worn,
-- shifted by its doctrine, never below one while it can fight at all.
function Squad.holds(member)
    if not member or not member.capable then return 0 end
    local utility = U()
    local fit = (tonumber(member.health) or 0)
            >= (tonumber(utility.config("combatSquadFitHealth")) or 70)
        and utility.characterStatValue(member.actor, "ENDURANCE", 1)
            >= (tonumber(utility.config("combatSquadFitEndurance")) or 0.5)
    local base = fit and (tonumber(utility.config("combatSquadZombiesPerFighter")) or 2) or 1
    local data = utility.modData(member.actor)
    local doctrine = type(data) == "table" and data.SC_CombatDoctrine or nil
    return math.max(1, base + (DOCTRINE_SHIFT[doctrine] or 0))
end

-- An arrival counts fully while close in time and fades to nothing later.
function Squad.arrivalWeight(ms)
    ms = tonumber(ms)
    if ms == nil then return 0 end
    local full = tonumber(U().config("combatSquadArrivalFullMs")) or 3000
    local zero = tonumber(U().config("combatSquadArrivalZeroMs")) or 8000
    if ms <= full then return 1 end
    if ms >= zero then return 0 end
    return (zero - ms) / (zero - full)
end

local function build(actor, snapshot, cohort, now, x, y, z, player, previous)
    local members = collectMembers(actor, snapshot, cohort, x, y, z)
    if #members < 2 then return nil end
    table.sort(members, function(a, b)
        return tostring(U().idOf(a.actor)) < tostring(U().idOf(b.actor))
    end)
    local views = { snapshot }
    for _, member in ipairs(members) do
        if member.actor ~= actor then
            local view = memberSnapshot(member.actor, now)
            if view and view ~= snapshot then views[#views + 1] = view end
        end
    end
    local threats = collectThreats(views, members, player, z)
    local capableCount, capacity, active, incoming, forecast = 0, 0, 0, 0, 0
    for _, member in ipairs(members) do
        if member.capable then capableCount = capableCount + 1 end
        member.holds = Squad.holds(member)
        capacity = capacity + member.holds
    end
    for _, threat in ipairs(threats) do
        if threat.distanceSq <= 4.5 * 4.5
            and (not threat.crawler or threat.distanceSq <= 2 * 2) then
            active, forecast = active + 1, forecast + 1
        else
            if threat.incoming then incoming = incoming + 1 end
            forecast = forecast + Squad.arrivalWeight(threat.arrivingMs)
        end
    end
    -- Fight while every zombie in reach is within the squad's capacity, give
    -- ground when it is not (now or within the forecast), and pull out when
    -- the arrivals would leave it well over.
    local margin = tonumber(U().config("combatSquadDisengageMargin")) or 2
    local wanted = "engage"
    if capableCount == 0 or forecast > capacity + margin then wanted = "disengage"
    elseif active > capacity or forecast > capacity then wanted = "give_ground"
    elseif #threats == 0 then wanted = "regroup" end
    local mode, modeSince = wanted, now
    local dwell = tonumber(U().config("combatSquadModeDwellMs")) or 1500
    if previous and previous.mode then
        local since = tonumber(previous.modeSince) or now
        if previous.mode == wanted then modeSince = since
        elseif wanted ~= "disengage" and now - since < dwell then
            mode, modeSince = previous.mode, since
        end
    end
    local held = assign(members, threats)
    local assignments = setmetatable({}, { __mode = "k" })
    for member, threat in pairs(held) do
        assignments[member.actor] = { mode = mode, target = threat.actor,
            protected = threat.victim, reason = threat.victim and "cover" or "engage" }
    end
    for _, member in ipairs(members) do
        if not assignments[member.actor] then
            local wounded
            for _, other in ipairs(members) do
                if other.health <= 55 and other.actor ~= member.actor then
                    wounded = other.actor break
                end
            end
            assignments[member.actor] = { mode = mode,
                protected = wounded, reason = wounded and "cover" or mode }
        end
    end
    return { cohort = cohort, x = x, y = y, z = z, members = members,
        assignments = assignments, threats = threats, mode = mode,
        supportProofs = setmetatable({}, { __mode = "k" }),
        active = active, incoming = incoming, capable = capableCount,
        capacity = capacity, forecast = forecast, wanted = wanted, modeSince = modeSince,
        refreshedAt = now, nextRefreshAt = now + 250, expires = now + 750 }
end

function Squad.forActor(actor, player, snapshot, cohort, now)
    if not actor or type(snapshot) ~= "table" then return nil end
    now = now or U().nowMs()
    local x, y, z = position(actor)
    if x == nil then return nil end
    local key = tostring(cohort) .. ":" .. tostring(math.floor(z or 0))
        .. ":" .. tostring(expeditionMember(actor))
    local plan
    for index = #plans, 1, -1 do
        local candidate = plans[index]
        if now >= candidate.expires then table.remove(plans, index)
        elseif candidate.key == key and distanceSq(x, y, candidate.x, candidate.y) <= 36 then
            plan = candidate break
        end
    end
    if not plan or now >= plan.nextRefreshAt or plan.assignments[actor] == nil then
        local performance = SC.Performance
        local started = performance and performance.preciseNowMs()
        local fresh = build(actor, snapshot, cohort, now, x, y, z, player, plan)
        if not fresh then return nil end
        fresh.key = key
        if plan then
            for index, candidate in ipairs(plans) do
                if candidate == plan then plans[index] = fresh break end
            end
        else plans[#plans + 1] = fresh end
        plan = fresh
        if started then performance.record("combat.squad-plan", nil,
            performance.preciseNowMs() - started, #fresh.threats, false) end
    end
    local assignment = plan.assignments[actor]
    if #plan.threats == 0 then return nil end
    if not assignment then return nil end
    -- Local pressure never waits for a cached squad assignment. A plan from a
    -- peer's view may miss the attacker now standing next to this companion.
    local view = { mode = plan.mode, target = assignment.target,
        protected = assignment.protected, reason = assignment.reason,
        refreshedAt = plan.refreshedAt, expires = plan.expires,
        active = plan.active, incoming = plan.incoming,
        capable = plan.capable, members = plan.members,
        capacity = plan.capacity, forecast = plan.forecast, holds = 1 }
    for _, member in ipairs(plan.members) do
        if member.actor == actor then view.holds = member.holds or 1 break end
    end
    -- Support is spent once. A member already assigned to another zombie is
    -- fighting it, not standing by for this one; a member held to a stay or
    -- guard spot only helps within reach of that spot.
    local support = 0
    for _, member in ipairs(plan.members) do
        local job = member.actor ~= actor and plan.assignments[member.actor] or nil
        local busy = job ~= nil and job.target ~= nil and job.target ~= assignment.target
        if member.actor ~= actor and member.capable and not busy
            and anchorReaches(member, x, y)
            and distanceSq(x, y, member.x, member.y) <= 36
            and sameGroup(actor, member.actor) then
            local proofs = plan.supportProofs[actor]
            local open = proofs and proofs[member.actor]
            if open == nil and Squad.positionProbe(now) and SC.Navigation then
                open = SC.Navigation.openSegment(member.actor, x, y, z, {
                    allowedBlocker = actor, allowGoalCharacterCrowd = true,
                }) == true
                proofs = proofs or setmetatable({}, { __mode = "k" })
                proofs[member.actor] = open
                plan.supportProofs[actor] = proofs
                local reverse = plan.supportProofs[member.actor]
                    or setmetatable({}, { __mode = "k" })
                reverse[actor] = open
                plan.supportProofs[member.actor] = reverse
            end
            if open then support = support + 1 end
        end
    end
    view.supportCount = support
    return view
end

-- Reject a flank before an expensive route proof when it crosses the crowd.
function Squad.safePosition(actor, target, x, y, z, snapshot, now)
    local ax, ay = position(actor)
    if ax == nil then return false end
    for index, threat in ipairs(snapshot.threats or {}) do
        if index > 64 then break end
        if threat.actor and threat.actor ~= target and threat.obstructed ~= true
            and (threat.posture ~= "downed" or threat.gettingUp == true) then
            local tx, ty, tz = tonumber(threat.x), tonumber(threat.y), tonumber(threat.z)
            if tx and (tz == nil or z == nil or math.floor(tz) == math.floor(z)) then
                if distanceSq(x, y, tx, ty) < (threat.attacking and 2.25 or 1.65) ^ 2 then
                    return false
                end
                local dx, dy = x - ax, y - ay
                local len2 = dx * dx + dy * dy
                if len2 > 0.01 then
                    local t = math.max(0, math.min(1,
                        ((tx - ax) * dx + (ty - ay) * dy) / len2))
                    if distanceSq(ax + t * dx, ay + t * dy, tx, ty) < 0.9 * 0.9 then
                        return false
                    end
                end
            end
        end
    end
    for _, ally in ipairs(snapshot.allies or {}) do
        local other = ally.actor
        if other ~= actor then
            local ox, oy = position(other)
            if ox and distanceSq(x, y, ox, oy) < 0.75 * 0.75 then return false end
        end
    end
    return Squad.positionProbe(now)
        and SC.Navigation and SC.Navigation.openSegment(actor, x, y, z) == true
end

function Squad.safeFinisher(actor, target, snapshot)
    local ax, ay, az = position(actor)
    if ax == nil then return false end
    for index, threat in ipairs(snapshot.threats or {}) do
        if index > 64 then break end
        if threat.actor and threat.actor ~= target and threat.obstructed ~= true then
            local tx, ty, tz = tonumber(threat.x), tonumber(threat.y), tonumber(threat.z)
            if tx == nil then tx, ty, tz = position(threat.actor) end
            local posture = threat.posture
            if posture == nil and SC.ZombieFacts then
                local facts = SC.ZombieFacts.get(threat.actor)
                posture = facts and facts.posture
            end
            -- Getting up is still a floor animation. Treat the zombie as a
            -- standing threat as soon as its posture actually becomes upright.
            if tx and (tz == nil or math.floor(tz) == math.floor(az or 0))
                and posture ~= "downed" then
                local closing = math.max(0, tonumber(threat.closingSpeed) or 0)
                local reach = 2.25 + math.min(2, closing * 1.5)
                if distanceSq(ax, ay, tx, ty) <= reach * reach then return false end
            end
        end
    end
    return true
end

function Squad.reset()
    plans, probeFrame, probes = {}, nil, 0
end

function Squad.releaseActor(actor)
    if actor == nil then return end
    for index = #plans, 1, -1 do
        local plan = plans[index]
        local affected = false
        for _, member in ipairs(plan.members) do
            if member.actor == actor then affected = true break end
        end
        if not affected then
            for _, threat in ipairs(plan.threats) do
                if threat.actor == actor then affected = true break end
            end
        end
        if affected then table.remove(plans, index) end
    end
end

return Squad
