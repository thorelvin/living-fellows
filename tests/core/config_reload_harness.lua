-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "config reload check " .. tostring(checks) .. " failed: " .. tostring(message))
end

check(SC.Config.get("maxCompanions") == 7
        and SC.Config.get("spawn", "maxCompanions") == 7
        and SC.Config.sections.spawn.maxCompanions == 7
        and SC_CONFIG_OLD_SECTIONS.spawn.maxCompanions == 7,
    "flat, section, current proxy, and retained proxy use the reloaded backing state")
check(SC.Config.defaults.maxCompanions == SC_CONFIG_OLD_DEFAULTS.maxCompanions
        and SC.Config.defaults.maxCompanions ~= SC.Config.get("maxCompanions"),
    "retained defaults proxy follows canonical defaults without absorbing overrides")
check(SC.Config.get("runtime", "circuitBreakerFailures")
        == SC.Config.get("runtime", "circuitBreakerErrors")
        and SC.Config._values.circuitBreakerFailures == nil,
    "legacy breaker alias resolves to one canonical backing key")
check(math.abs(SC.Config.get("uiPanelOpacity") - 0.72) < 0.001,
    "module reload refreshes the current sandbox source")

print("CONFIG_RELOAD_KAHLUA_PASS checks=" .. tostring(checks))
