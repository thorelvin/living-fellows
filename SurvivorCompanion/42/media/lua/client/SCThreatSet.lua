-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.ThreatSet = SC.ThreatSet or {}
local ThreatSet = SC.ThreatSet

function ThreatSet.threatPreferred(a, b)
    if a.score == b.score then return a.distanceSq < b.distanceSq end
    return a.score > b.score
end

function ThreatSet.proximityPreferred(a, b)
    if a.distanceSq == b.distanceSq then return a.score > b.score end
    return a.distanceSq < b.distanceSq
end

function ThreatSet.isImmediate(record, immediateRadiusSq, attackCommitRadius)
    if type(record) ~= "table" then return false end
    if (tonumber(record.distanceSq) or math.huge) <= immediateRadiusSq then return true end
    local cap = tonumber(attackCommitRadius) or 1.5
    return record.attacking == true
        and (tonumber(record.distanceSq) or math.huge) <= cap * cap
end

local function retainBest(list, record, limit, preferred)
    if #list < limit then
        list[#list + 1] = record
        return
    end
    local worst = 1
    for index = 2, #list do
        if preferred(list[worst], list[index]) then worst = index end
    end
    if preferred(record, list[worst]) then list[worst] = record end
end

function ThreatSet.new(limit, immediateRadiusSq, attackCommitRadius)
    return {
        limit = math.max(1, math.floor(tonumber(limit) or 32)),
        immediateRadiusSq = tonumber(immediateRadiusSq) or 0,
        attackCommitRadius = tonumber(attackCommitRadius) or 1.5,
        seen = setmetatable({}, { __mode = "k" }),
        immediateCandidates = {}, ordinaryCandidates = {}, stealthCandidates = {},
        visibleCount = 0, immediateVisibleCount = 0, added = 0,
    }
end

function ThreatSet.add(set, record, discovered)
    if type(set) ~= "table" or type(record) ~= "table" or record.actor == nil then
        return false
    end
    if set.seen[record.actor] then return false end
    set.seen[record.actor] = true
    set.visibleCount = set.visibleCount + 1
    retainBest(set.stealthCandidates, record, set.limit, ThreatSet.proximityPreferred)
    if ThreatSet.isImmediate(record, set.immediateRadiusSq, set.attackCommitRadius) then
        set.immediateVisibleCount = set.immediateVisibleCount + 1
        retainBest(set.immediateCandidates, record, set.limit, ThreatSet.proximityPreferred)
    else
        retainBest(set.ordinaryCandidates, record, set.limit, ThreatSet.threatPreferred)
    end
    if discovered == true then set.added = set.added + 1 end
    return true
end

function ThreatSet.finish(set)
    local threats, immediate, fenced, grounded = {}, {}, {}, {}
    table.sort(set.immediateCandidates, ThreatSet.proximityPreferred)
    table.sort(set.ordinaryCandidates, ThreatSet.threatPreferred)
    for _, record in ipairs(set.immediateCandidates) do
        if #threats >= set.limit then break end
        threats[#threats + 1] = record
    end
    for _, record in ipairs(set.ordinaryCandidates) do
        if #threats >= set.limit then break end
        threats[#threats + 1] = record
    end
    table.sort(threats, ThreatSet.threatPreferred)
    for _, record in ipairs(threats) do
        if record.grounded then grounded[#grounded + 1] = record end
        if ThreatSet.isImmediate(record, set.immediateRadiusSq, set.attackCommitRadius) then
            immediate[#immediate + 1] = record
        end
        if record.fenced then fenced[#fenced + 1] = record end
    end
    local stealth = set.stealthCandidates
    table.sort(stealth, ThreatSet.proximityPreferred)
    table.sort(immediate, ThreatSet.proximityPreferred)
    return {
        threats = threats,
        immediate = immediate,
        fenced = fenced,
        grounded = grounded,
        stealth = stealth,
        visibleCount = set.visibleCount,
        immediateVisibleCount = set.immediateVisibleCount,
        threatOverflow = math.max(0, set.visibleCount - #threats),
        immediateOverflow = math.max(0, set.immediateVisibleCount - #immediate),
        added = set.added,
    }
end

return ThreatSet
