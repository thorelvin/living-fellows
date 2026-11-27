-- SPDX-License-Identifier: MIT
-- The foundation harness drives the Strange Folk registry with no encounter
-- behaviour loaded. Encounter save checks live in each encounter's module
-- (saveRules), so the group loads those modules and this fixture keeps only
-- their real save rules: every registry lookup for behaviour still finds
-- nothing, exactly as before.

local SC = SurvivorCompanion
local RULE_MODULES = {
    "OddballCaleb", "OddballCampStoryteller", "OddballRoom12", "OddballSurvivalist",
    "OddballVoiceActor", "OddballGarageRescue", "OddballDehydrated", "OddballPyromaniac",
    "OddballJune", "OddballCrabtree", "OddballJedediah", "OddballGideon", "OddballRenfro",
    "OddballTommy", "OddballBigChris", "OddballMilli", "OddballPurdy",
}
for _, name in ipairs(RULE_MODULES) do
    local module = SC[name]
    assert(type(module) == "table" and type(module.saveRules) == "table",
        "save rules fixture: " .. name .. " is not loaded or has no saveRules")
    SC[name] = { saveRules = module.saveRules }
end
