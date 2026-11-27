-- SPDX-License-Identifier: MIT
-- Groups that drive the faction layer and the Strange Folk registry with no
-- encounter behaviour loaded. What the faction layer asks of one encounter
-- lives in that encounter's module (storyRules, and June's loose-rabbit
-- reaction, which SCFactions used to run itself), so such a group loads the
-- modules it needs and this fixture keeps only those: every other registry
-- lookup for behaviour still finds nothing, exactly as before.

local SC = LivingFellows
local kept = {}
for name, module in pairs(SC) do
    if type(name) == "string" and name ~= "Oddballs" and string.sub(name, 1, 7) == "Oddball"
        and type(module) == "table" and type(module.storyRules) == "table" then
        kept[#kept + 1] = name
    end
end
assert(#kept > 0, "story rules fixture: no encounter module with storyRules is loaded")
for _, name in ipairs(kept) do
    SC[name] = { storyRules = SC[name].storyRules,
        onWildAnimalHurt = SC[name].onWildAnimalHurt }
end
