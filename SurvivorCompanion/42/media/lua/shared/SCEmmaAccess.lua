-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
local Access = {}
SC.EmmaAccess = Access

function Access.enabled()
    local options = type(SandboxVars) == "table" and SandboxVars.LivingFellows
    return type(options) ~= "table" or options.EmmaEnabled ~= false
end

function Access.disabledText()
    return SC.GameplayUtil.text("UI_SC_Terminal_Disabled", "EMMA is disabled in Sandbox Options.")
end

return Access
