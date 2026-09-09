-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.Allegiance = SC.Allegiance or {}
local Allegiance = SC.Allegiance

local function hostileGroup(group)
    return type(group) == "table" and (group.archetype == "bandit_camp"
        or group.standing == "Hostile" or group.lifecycle == "hostile")
end

-- Facts are resolved by SCFactions so this policy remains independent of the
-- mutable registry. Direction is intentional: bandits may challenge before a
-- player-party actor is allowed to attack them, while bandits themselves remain
-- hostile to a party member once that party member is a valid target.
function Allegiance.isHostile(facts)
    if type(facts) ~= "table" or facts.sourceExists ~= true
        or facts.targetExists ~= true or facts.same == true then return false end
    local sourceAffiliation = facts.sourceAffiliation
    local targetAffiliation = facts.targetAffiliation
    if sourceAffiliation and facts.targetParty == true then
        return hostileGroup(sourceAffiliation.group)
    end
    if targetAffiliation and facts.sourceParty == true then
        local group = targetAffiliation.group
        if type(group) ~= "table" then return false end
        if group.archetype == "bandit_camp" then
            return type(group.bandit) == "table" and group.bandit.engagement ~= "unaware"
        end
        return group.standing == "Hostile" or group.lifecycle == "hostile"
    end
    return false
end

function Allegiance.relationship(facts)
    if type(facts) ~= "table" or facts.sourceExists ~= true
        or facts.targetExists ~= true then return "unknown" end
    if facts.same == true then return "self" end
    if facts.sourceParty == true and facts.targetParty == true then return "party_ally" end
    local sourceAffiliation = facts.sourceAffiliation
    local targetAffiliation = facts.targetAffiliation
    if sourceAffiliation and targetAffiliation
        and sourceAffiliation.factionId == targetAffiliation.factionId then
        return "faction_ally"
    end
    if Allegiance.isHostile(facts) then return "hostile" end
    return "neutral"
end

function Allegiance.areAllies(facts)
    local relationship = Allegiance.relationship(facts)
    return relationship == "party_ally" or relationship == "faction_ally"
end

function Allegiance.isProtected(facts)
    local relationship = Allegiance.relationship(facts)
    return relationship == "party_ally" or relationship == "faction_ally"
        or relationship == "neutral"
end

return Allegiance
