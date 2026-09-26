-- SPDX-License-Identifier: MIT
-- A horde in sight is not a horde in the fight.
--
-- `snapshot.pressure` mixed two unrelated things: the zombies that can actually
-- reach this companion, and every other one it happens to be able to see, at
-- 0.35 apiece. Retreat utility multiplies pressure by 16 and the attack scores
-- subtract multiples of it, so twenty idle zombies across a field moved retreat
-- by +112 and melee by -21 without one fact about the fight in front of the
-- companion having changed. Companions kited away from a pair of zombies they
-- could comfortably have handled.
--
-- This module derives the three meanings separately, from one place, so the
-- full sensing pass and the reflex refresh cannot drift apart:
--
--   local     -- can I safely perform this next action?
--   incoming  -- can we cover what is about to arrive?
--   ambient   -- will staying here, or making noise, involve the rest of them?
--
-- It performs no navigation, native or world calls. Given the same observation
-- it returns the same numbers.
local SC = SurvivorCompanion
SC.CombatThreatModel = SC.CombatThreatModel or {}
local Model = SC.CombatThreatModel

Model.VERSION = 1

local function U() return SC.GameplayUtil end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function config(key, fallback)
    local utility = U()
    local value = utility and utility.config and utility.config(key) or nil
    return finite(value, fallback)
end

-- How far ahead an arrival still counts as something to plan around. Beyond it
-- a contact is awareness, not a reason to break off a swing already underway.
function Model.horizonMs()
    return math.max(1000, config("combatIncomingHorizonMs", 5000))
end

-- The zombies that can reach this companion. Same shape the old expression had,
-- but its second term counts only contacts inside the close envelope instead of
-- everything visible, so a distant crowd contributes nothing here.
function Model.localPressure(immediateCount, closeThreatCount, closeImmediateCount)
    local immediate = math.max(0, finite(immediateCount, 0))
    local close = math.max(0, finite(closeThreatCount, 0))
    local closeImmediate = math.max(0, finite(closeImmediateCount, immediate))
    return immediate * 1.5 + math.max(0, close - closeImmediate) * 0.35
end

-- Credible arrivals. A contact counts as incoming only on observed closing
-- motion with an estimated arrival inside the horizon -- the motion history the
-- combat target scorer already keeps, reused rather than rebuilt. A companion
-- walking toward a stationary crowd closes the distance too, which is a reason
-- for route caution and not evidence that anything is chasing anybody.
function Model.incoming(threats, horizonMs)
    horizonMs = math.max(1, finite(horizonMs, Model.horizonMs()))
    local count, earliest = 0, nil
    for _, threat in ipairs(type(threats) == "table" and threats or {}) do
        if type(threat) == "table" and threat.close ~= true then
            local closing = finite(threat.closingSpeed, 0)
            local arrival = finite(threat.timeToImpactMs, nil)
            if closing > 0.01 and arrival ~= nil and arrival >= 0 and arrival <= horizonMs then
                count = count + 1
                if earliest == nil or arrival < earliest then earliest = arrival end
            end
        end
    end
    return count, count * 0.35, earliest
end

-- What is left is awareness. It is deliberately not a number anybody multiplies
-- by sixteen: it informs caution, route choice and noise policy, and nothing
-- that decides whether this swing is safe.
function Model.ambientCaution(ambientCount)
    local count = math.max(0, finite(ambientCount, 0))
    if count <= 0 then return 0 end
    return math.min(1, count / 12)
end

-- An empty escape list used to imply encirclement whenever two zombies were
-- visible anywhere. A search that has not run, or could not run, is not proof
-- that a companion is surrounded -- but it is not proof of safety either, so it
-- is reported as its own state rather than folded into one boolean.
function Model.escapeStatus(escapeSquares, closeThreatCount)
    local candidates = type(escapeSquares) == "table" and #escapeSquares or 0
    if candidates > 0 then return "verified", candidates end
    if math.max(0, finite(closeThreatCount, 0)) > 0 then return "blocked", 0 end
    return "unknown", 0
end

-- One observation, classified. Callers pass what they already counted; this
-- adds no scanning of its own.
function Model.derive(observation)
    observation = type(observation) == "table" and observation or {}
    local immediate = math.max(0, finite(observation.immediateCount, 0))
    local close = math.max(0, finite(observation.closeThreatCount, 0))
    local closeImmediate = math.max(0, finite(observation.closeImmediateCount, immediate))
    local visible = math.max(0, finite(observation.visibleCount, 0))
    local occupied = math.max(0, finite(observation.occupiedThreatSectors, 0))

    local horizon = math.max(1, finite(observation.horizonMs, Model.horizonMs()))
    local incomingCount, incomingPressure, earliest = Model.incoming(observation.threats, horizon)
    local localPressure = Model.localPressure(immediate, close, closeImmediate)
    local ambientCount = math.max(0, visible - close - incomingCount)
    local status, candidates = Model.escapeStatus(observation.escapeSquares, close)

    return {
        localPressure = localPressure,
        incomingCount = incomingCount,
        incomingPressure = incomingPressure,
        earliestContactMs = earliest,
        horizonMs = horizon,
        ambientCount = ambientCount,
        ambientCaution = Model.ambientCaution(ambientCount),
        escapeStatus = status,
        escapeCandidates = candidates,
        -- Proven multi-sided pressure only. An unknown route is handled by
        -- escapeStatus, which the retreat calculation reads separately.
        encircled = closeImmediate >= 3 or occupied >= 3,
    }
end

-- What combat should weigh when deciding whether this next action is safe: the
-- fight in front of the actor, plus what is about to join it. Ambient sightings
-- are deliberately absent. Snapshots built before this model existed still
-- answer with their legacy value so nothing silently reads zero.
function Model.engagementPressure(snapshot)
    if type(snapshot) ~= "table" then return 0 end
    local derived = finite(snapshot.localPressure, nil)
    if derived == nil then return math.max(0, finite(snapshot.pressure, 0)) end
    return math.max(0, derived) + math.max(0, finite(snapshot.incomingPressure, 0))
end

-- Applies a derivation onto a snapshot table. Both sensing writers use this, so
-- a full scan and a reflex refresh cannot disagree about the same facts.
function Model.apply(snapshot, observation)
    if type(snapshot) ~= "table" then return nil end
    local derived = Model.derive(observation)
    snapshot.localPressure = derived.localPressure
    snapshot.incomingCount = derived.incomingCount
    snapshot.incomingPressure = derived.incomingPressure
    snapshot.earliestContactMs = derived.earliestContactMs
    snapshot.incomingHorizonMs = derived.horizonMs
    snapshot.ambientCount = derived.ambientCount
    snapshot.ambientCaution = derived.ambientCaution
    snapshot.escapeStatus = derived.escapeStatus
    snapshot.encircled = derived.encircled
    return derived
end

return Model
