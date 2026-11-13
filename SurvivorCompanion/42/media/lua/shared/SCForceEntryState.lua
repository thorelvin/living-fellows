-- SPDX-License-Identifier: MIT
-- Shared order data only: no actor references, inventory reads or services.
require "SCNamespace"
SurvivorCompanion.ForceEntryState = SurvivorCompanion.ForceEntryState or {}
function SurvivorCompanion.ForceEntryState.copy(value)
    if type(value) ~= "table" then return nil end
    local result = { attempted = value.attempted == true }
    for _, key in ipairs({ "useId", "stage", "result", "toolId", "sourceId", "missionId" }) do
        if type(value[key]) == "string" and #value[key] <= 160 then result[key] = value[key] end
    end
    local deadline = value.deadlineAt
    if type(deadline) == "number" and deadline == deadline and deadline >= 0 and deadline < math.huge then
        result.deadlineAt = deadline
    end
    return result
end
