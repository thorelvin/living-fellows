-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
SC_CONFIG_OLD_DEFAULTS = SC.Config.defaults
SC_CONFIG_OLD_SECTIONS = SC.Config.sections
local refreshed = SC.Config.refreshSandbox({ LivingFellows = {
    MaxCompanions = 5,
    UIOpacity = 0.55,
} })
assert(refreshed and SC.Config.get("maxCompanions") == 5,
    "first configuration instance did not accept sandbox overrides")
SandboxVars = { LivingFellows = {
    MaxCompanions = 7,
    UIOpacity = 0.72,
} }
