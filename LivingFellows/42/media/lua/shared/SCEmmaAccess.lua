-- SPDX-License-Identifier: MIT

LivingFellows = LivingFellows or {}
local SC = LivingFellows
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
