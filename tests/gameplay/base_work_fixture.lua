-- SPDX-License-Identifier: MIT
-- The gameplay runner has no vanilla timed-action globals at module load.
ISBuildAction = ISBuildAction or {}
function ISBuildAction:derive()
    return setmetatable({}, { __index = self })
end
