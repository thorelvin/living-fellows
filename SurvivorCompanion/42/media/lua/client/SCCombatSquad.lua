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

local function capable(actor, health)
    if not actor or U().isDead(actor) or (tonumber(health) or 100) <= 50 then
        return false
    end
    if SC.Medical and type(SC.Medical.isDowned) == "function"
        and SC.Medical.isDowned(actor) then return false end
    if U().characterStatValue(actor, "ENDURANCE", 0.5) <= 0.25 then return false end
    local combat = SC.Combat
    if combat and type(combat.primaryWeaponUsable) == "function"
        and combat.primaryWeaponUsable(actor) == true then return true end
    return combat and type(combat.unarmedResponse) == "function"
        and combat.unarmedResponse(actor) == "fight" or false
end

local function collectMembers(actor, snapshot, cohort, x, y, z)
    local actorHealth = U().nativeHealth(actor)
    local party = string.sub(tostring(cohort), 1, 6) == "party:"
    local members = {
        { actor = actor, x = x, y = y, z = z,
            health = actorHealth, capable = capable(actor, actorHealth) },
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
                members[#members + 1] = { actor = other, x = ox, y = oy,
                    z = oz, health = health, capable = capable(other, health) }
            end
        end
    end
    return members
end

local function collectThreats(snapshot, x, y, z)
    local threats = {}
    for index, threat in ipairs(snapshot.threats or {}) do
        if index > 64 then break end
        local other = threat.actor
        if other and not U().isDead(other) and threat.obstructed ~= true
            and threat.visible ~= false then
            local tx, ty, tz = tonumber(threat.x), tonumber(threat.y), tonumber(threat.z)
            if not tx then tx, ty, tz = position(other) end
            if tx and (tz == nil or math.floor(tz) == math.floor(z)) then
                local facts = SC.ZombieFacts and SC.ZombieFacts.get(other) or nil
                local posture = facts and facts.posture or threat.posture
                if posture ~= "downed" or (facts and facts.gettingUp) then
                    local d2 = distanceSq(x, y, tx, ty)
                    local arriving = tonumber(threat.timeToImpactMs)
                    if (posture ~= "crawler" or d2 <= 2 * 2
                        or (arriving ~= nil and arriving <= 5000))
                        and (d2 <= 6 * 6 or (d2 <= 12 * 12
                            and arriving ~= nil and arriving <= 5000)) then
                        local victim = facts and facts.target or threat.target
                        local priority = (threat.attacking and 50 or 0)
                            + (victim and 25 or 0) + 30 / (1 + math.sqrt(d2))
                            + math.max(0, 5 - (arriving or 99999) / 1000) * 3
                        threats[#threats + 1] = { actor = other, x = tx, y = ty,
                            distanceSq = d2, victim = victim, priority = priority,
                            attacking = threat.attacking == true,
                            crawler = posture == "crawler",
                            incoming = arriving ~= nil and arriving <= 5000 }
                    end
                end
            end
        end
    end
    table.sort(threats, function(a, b)
        if a.priority == b.priority then return a.distanceSq < b.distanceSq end
        return a.priority > b.priority
    end)
    return threats
end

local function build(actor, snapshot, cohort, now, x, y, z)
    local members = collectMembers(actor, snapshot, cohort, x, y, z)
    if #members < 2 then return nil end
    local threats = collectThreats(snapshot, x, y, z)
    local capableCount, active, incoming = 0, 0, 0
    for _, member in ipairs(members) do
        if member.capable then capableCount = capableCount + 1 end
    end
    for _, threat in ipairs(threats) do
        if threat.distanceSq <= 4.5 * 4.5
            and (not threat.crawler or threat.distanceSq <= 2 * 2) then
            active = active + 1
        elseif threat.incoming then incoming = incoming + 1 end
    end
    local load = active + math.min(incoming, capableCount + 2)
    local mode = "engage"
    if capableCount == 0 or load > capableCount * 2 + 2 then mode = "disengage"
    elseif load > capableCount + 1 then mode = "give_ground"
    elseif #threats == 0 then mode = "regroup" end
    local assignments = setmetatable({}, { __mode = "k" })
    for _, threat in ipairs(threats) do
        local best, bestScore
        for _, member in ipairs(members) do
            if member.capable and assignments[member.actor] == nil then
                local d2 = distanceSq(member.x, member.y, threat.x, threat.y)
                if d2 <= 6 * 6 then
                    local score = d2 - (threat.victim == member.actor and 3 or 0)
                    if bestScore == nil or score < bestScore then
                        best, bestScore = member, score
                    end
                end
            end
        end
        if best then
            assignments[best.actor] = { mode = mode, target = threat.actor,
                protected = threat.victim, reason = threat.victim and "cover" or "engage" }
        end
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
        local fresh = build(actor, snapshot, cohort, now, x, y, z)
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
        capable = plan.capable, members = plan.members }
    local support = 0
    for _, member in ipairs(plan.members) do
        if member.actor ~= actor and member.capable
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
